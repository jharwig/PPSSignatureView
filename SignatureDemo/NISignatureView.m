//
//  NISignatureView.m
//  SignatureViewTest
//
//  Created by Jason Harwig on 11/5/12.
//  Copyright (c) 2012 Near Infinity Corporation. All rights reserved.
//

#import "NISignatureView.h"

#define             STROKE_WIDTH_MIN 0.002 // Stroke width determined by touch velocity
#define             STROKE_WIDTH_MAX 0.010
#define       STROKE_WIDTH_SMOOTHING 0.5   // Low pass filter alpha

#define           VELOCITY_CLAMP_MIN 20
#define           VELOCITY_CLAMP_MAX 5000

#define QUADRATIC_DISTANCE_TOLERANCE 3.0   // Minimum distance to make a curve

#define             MAXIMUM_VERTECES 100000


static GLKVector3 StrokeColor = { 0, 0, 0 };

// Vertex structure containing 3D point and color
struct NISignaturePoint
{
	GLKVector3		vertex;
	GLKVector3		color;
};
typedef struct NISignaturePoint NISignaturePoint;


// Maximum verteces in signature
static const int maxLength = MAXIMUM_VERTECES;


// Append vertex to array buffer
static inline void addVertex(NSUInteger *length, NISignaturePoint v) {
    if ((*length) >= maxLength) {
        return;
    }
    
    GLvoid *data = glMapBufferOES(GL_ARRAY_BUFFER, GL_WRITE_ONLY_OES);
    memcpy(data + sizeof(NISignaturePoint) * (*length), &v, sizeof(NISignaturePoint));
    glUnmapBufferOES(GL_ARRAY_BUFFER);
    
    (*length)++;
}


static float clamp(min, max, value) { return fmaxf(min, fminf(max, value)); }


// Find perpendicular vector from two other vectors to compute triangle strip around line
static GLKVector3 perpendicular(NISignaturePoint p1, NISignaturePoint p2) {
    GLKVector3 ret;
    ret.x = p2.vertex.y - p1.vertex.y;
    ret.y = -1 * (p2.vertex.x - p1.vertex.x);
    ret.z = 0;
    return ret;
}



@implementation NISignatureView

// OpenGL state
EAGLContext *context;
GLKBaseEffect *effect;
GLuint vertexArray;
GLuint vertexBuffer;


// Array of verteces, with current length
NISignaturePoint SignatureVertexData[maxLength];
NSUInteger length;


// Width of line at current and previous vertex
float penThickness;
float previousThickness;


// Previous points for quadratic bezier computations
CGPoint previousPoint;
CGPoint previousMidPoint;
NISignaturePoint previousVertex;



- (void)commonInit {
    context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    
    if (context) {        
        self.context = context;
        self.drawableDepthFormat = GLKViewDrawableDepthFormat24;
        
        // Turn on antialiasing
        self.drawableMultisample = GLKViewDrawableMultisample4X;
        
        [self setupGL];
        
        // Capture touches
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(pan:)];
        pan.maximumNumberOfTouches = pan.minimumNumberOfTouches = 1;
        [self addGestureRecognizer:pan];
        
        // Erase with long press
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(erase)]];

    } else [NSException raise:@"NSOpenGLES2ContextException" format:@"Failed to create OpenGL ES2 context"];
}


- (id)initWithCoder:(NSCoder *)aDecoder
{
    if (self = [super initWithCoder:aDecoder]) [self commonInit];
    return self;
}


- (id)initWithFrame:(CGRect)frame context:(EAGLContext *)context
{
    if (self = [super initWithFrame:frame context:context]) [self commonInit];
    return self;
}


- (void)dealloc
{
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == context) {
        [EAGLContext setCurrentContext:nil];
    }
	context = nil;
}


- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);
    
    if (length > 2) {
        glDrawArrays(GL_TRIANGLE_STRIP, 0, length);
    }
}


- (void)erase {
    length = 0;
}



#pragma mark - Gesture Recognizers



- (void)pan:(UIPanGestureRecognizer *)p {
    CGPoint v = [p velocityInView:self];
    CGPoint l = [p locationInView:self];
    
    float distance = sqrtf((l.x - previousPoint.x) * (l.x - previousPoint.x) + (l.y - previousPoint.y) * (l.y - previousPoint.y));
    float velocityMagnitude = sqrtf(v.x*v.x + v.y*v.y);
    float clampedVelocityMagnitude = clamp(VELOCITY_CLAMP_MIN, VELOCITY_CLAMP_MAX, velocityMagnitude);
    float normalizedVelocity = (clampedVelocityMagnitude - VELOCITY_CLAMP_MIN) / (VELOCITY_CLAMP_MAX - VELOCITY_CLAMP_MIN);
    
    float lowPassFilterAlpha = STROKE_WIDTH_SMOOTHING;
    float newThickness = (STROKE_WIDTH_MAX - STROKE_WIDTH_MIN) * normalizedVelocity + STROKE_WIDTH_MIN;
    penThickness = penThickness * lowPassFilterAlpha + newThickness * (1 - lowPassFilterAlpha);
    
    if ([p state] == UIGestureRecognizerStateBegan) {
        
        previousPoint = l;
        previousMidPoint = l;
        
        NISignaturePoint startPoint = {
            {    (l.x / self.bounds.size.width * 2. - 1), ((l.y / self.bounds.size.height) * 2.0 - 1) * -1, 0}, {1,1,1}
        };
        previousVertex = startPoint;
        previousThickness = penThickness;
        
        addVertex(&length, startPoint);
        addVertex(&length, previousVertex);
        
    } else if ([p state] == UIGestureRecognizerStateChanged) {
        
        CGPoint mid = CGPointMake((l.x + previousPoint.x) / 2.0, (l.y + previousPoint.y) / 2.0);
        
        if (distance > QUADRATIC_DISTANCE_TOLERANCE) {
            // Plot quadratic bezier instead of line
            unsigned int i;
            
            int segments = (int) distance / 1.5;
            
            float startPenThickness = previousThickness;
            float endPenThickness = penThickness;
            previousThickness = penThickness;
            
            for (i = 0; i < segments; i++)
            {
                penThickness = startPenThickness + ((endPenThickness - startPenThickness) / segments) * i;
                double t = (double)i / (double)segments;
                double a = pow((1.0 - t), 2.0);
                double b = 2.0 * t * (1.0 - t);
                double c = pow(t, 2.0);
                double x = a * previousMidPoint.x + b * previousPoint.x + c * mid.x;
                double y = a * previousMidPoint.y + b * previousPoint.y + c * mid.y;
                
                NISignaturePoint v = {
                    {
                        (x / self.bounds.size.width * 2. - 1),
                        ((y / self.bounds.size.height) * 2.0 - 1) * -1,
                        0
                    },
                    StrokeColor
                };
                
                [self addTriangleStripPointsForPrevious:previousVertex next:v];
                
                previousVertex = v;
            }
        } else if (distance > 1.0) {
            NISignaturePoint v = {
                {    (l.x / self.bounds.size.width * 2. - 1), ((l.y / self.bounds.size.height) * 2.0 - 1) * -1, 0},
                StrokeColor
            };
            [self addTriangleStripPointsForPrevious:previousVertex next:v];
            previousVertex = v;            
            previousThickness = penThickness;
        }
        
        previousPoint = l;
        previousMidPoint = mid;

    } else if (p.state == UIGestureRecognizerStateEnded | p.state == UIGestureRecognizerStateCancelled) {

        NISignaturePoint v = {
            {    (l.x / self.bounds.size.width * 2. - 1), ((l.y / self.bounds.size.height) * 2.0 - 1) * -1, 0},
            { 1.0, 1.0, 1.0 }
        };
        addVertex(&length, v);
        
        previousVertex = v;
        addVertex(&length, previousVertex);
    }
}



#pragma mark - Private



- (void)setupGL
{
    [EAGLContext setCurrentContext:context];
    
    effect = [[GLKBaseEffect alloc] init];
    
    glDisable(GL_DEPTH_TEST);
    glGenVertexArraysOES(1, &vertexArray);
    glBindVertexArrayOES(vertexArray);
    
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);
    
    length = 0;
    penThickness = 0.02;
    
    glBufferData(GL_ARRAY_BUFFER, sizeof(SignatureVertexData), SignatureVertexData, GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(GLKVertexAttribPosition);
    glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof(NISignaturePoint), 0);
    glEnableVertexAttribArray(GLKVertexAttribColor);
    glVertexAttribPointer(GLKVertexAttribColor, 3, GL_FLOAT, GL_FALSE,  6 * sizeof(GLfloat), (char *)12);
    
    glBindVertexArrayOES(0);
    glClearColor(1, 1, 1, 1.0f);

    // Perspective
    GLKMatrix4 ortho = GLKMatrix4MakeOrtho(-1, 1, -1, 1, 0.1f, 100.0f);
    effect.transform.projectionMatrix = ortho;
    
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -0.1f);
    effect.transform.modelviewMatrix = modelViewMatrix;
    
    // Setup drawing of signature
    glBindVertexArrayOES(vertexArray);
    [effect prepareToDraw];
    
    previousPoint = CGPointMake(-100, -100);
}



- (void)addTriangleStripPointsForPrevious:(NISignaturePoint)previous next:(NISignaturePoint)next {
    float toTravel = penThickness / 2.0;
    
    for (int i = 0; i < 2; i++) {
        GLKVector3 p = perpendicular(previous, next);
        GLKVector3 p1 = next.vertex;
        GLKVector3 ref = GLKVector3Add(p1, p);
        
        float distance = GLKVector3Distance(p1, ref);
        float difX = p1.x - ref.x;
        float difY = p1.y - ref.y;
        float ratio = -1.0 * (toTravel / distance);
        
        difX = difX * ratio;
        difY = difY * ratio;
                
        NISignaturePoint stripPoint = {
            { p1.x + difX, p1.y + difY, 0.0 },
            StrokeColor
        };
        addVertex(&length, stripPoint);
        
        toTravel *= -1;
    }
}


- (void)tearDownGL
{
    [EAGLContext setCurrentContext:context];
    
    glDeleteBuffers(1, &vertexBuffer);
    glDeleteVertexArraysOES(1, &vertexArray);
    
    effect = nil;
}


@end
