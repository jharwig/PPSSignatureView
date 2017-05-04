#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

@interface PPSSignatureView : GLKView

@property (assign, nonatomic) float rotationScaleRatio;
@property (assign, nonatomic) UIColor *strokeColor;
@property (readonly, nonatomic) BOOL hasSignature;
@property (readonly, nonatomic) UIImage *signatureImage;

- (void)erase;

@end
