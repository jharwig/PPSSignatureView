#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

@protocol PPSSignatureViewDelegate;

@interface PPSSignatureView : GLKView

@property (assign, nonatomic) UIColor *strokeColor;
@property (assign, nonatomic) BOOL hasSignature;
@property (strong, nonatomic) UIImage *signatureImage;
@property(assign, nonatomic) BOOL longPressToEraseEnabled;
@property(nonatomic,readonly) NSUInteger vertexCount;
@property(weak, nonatomic)id<PPSSignatureViewDelegate> signatureViewDelegate;

- (void)erase;

@end


@protocol PPSSignatureViewDelegate <NSObject>
-(void)signatureDidChange:(PPSSignatureView*)signatureView;
@end