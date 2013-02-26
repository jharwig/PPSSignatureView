//
//  NISignatureView.h
//  SignatureViewTest
//
//  Created by Jason Harwig on 11/5/12.
//  Copyright (c) 2012 Near Infinity Corporation.

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

@interface NISignatureView : GLKView


- (void)erase;
- (UIImage *) getSignatureImage;

@end
