//
//  UIImage+Segment.swift
//  MetalEasyFoundation
//
//  Created by LangFZ on 2019/7/13.
//  Copyright © 2019 LFZ. All rights reserved.
//

import UIKit
import VideoToolbox

extension UIImage {

    public func segmentation() -> CGImage? {
        
        guard var cgImage = self.coarseSegmentation() else {
            return nil
        }
        
        let outputWidth: CGFloat = 500
        let outputSize = CGSize.init(width: outputWidth, height: outputWidth * self.size.height / self.size.width)
        let resizeImg = UIImage.init(cgImage: cgImage).resize(size: outputSize)!
        let ciImg = CIImage.init(cgImage: resizeImg.cgImage!)
        
        let smoothFilter = SmoothFillter.init()
        smoothFilter.inputImage = ciImg
        
        let outputImage = smoothFilter.outputImage!
        let ciContext = CIContext.init(options: nil)
        cgImage = ciContext.createCGImage(outputImage, from: ciImg.extent)!
        
        return cgImage
    }
    
    public func coarseSegmentation() -> CGImage? {
        
        let segment = Segment.init()
        let pixBuf = self.pixelBuffer(width: 513, height: 513)
        
        guard let output = try? segment.prediction(ImageTensor__0: pixBuf!) else {
            return nil
        }
        
        let shape = output.ResizeBilinear_2__0.shape
        let (d, w, h) = (Int(truncating: shape[0]), Int(truncating: shape[1]), Int(truncating: shape[2]))
        let pageSize = w * h
        var res:Array<Int> = []
        var pageIndexs:Array<Int> = []
        
        for i in 0..<d {
            pageIndexs.append(pageSize * i)
        }
        
        func argmax(arr:Array<Int>) -> Int {
            
            precondition(arr.count > 0)
            var maxValue = arr[0]
            var maxValueIndex = 0
            
            for i in 1..<arr.count {
                if arr[i] > maxValue {
                    maxValue = arr[i]
                    maxValueIndex = i
                }
            }
            
            return maxValueIndex
        }
        
        for i in 0..<w {
            
            for j in 0..<h {
                
                var itemArr:Array<Int> = []
                let pageOffset = i * w + j
                
                for k in 0..<d {
                    
                    let padding = pageIndexs[k]
                    itemArr.append(Int(truncating: output.ResizeBilinear_2__0[padding + pageOffset]))
                }
                
                /*
                 types map  [
                 'background', 'aeroplane', 'bicycle', 'bird', 'boat', 'bottle', 'bus',
                 'car', 'cat', 'chair', 'cow', 'diningtable', 'dog', 'horse', 'motorbike',
                 'person', 'pottedplant', 'sheep', 'sofa', 'train', 'tv'
                 ]
                 */
                let type = argmax(arr: itemArr)
                res.append(type)
            }
        }
        
        let bytesPerComponent = MemoryLayout<UInt8>.size
        let bytesPerPixel = bytesPerComponent * 4
        let length = pageSize * bytesPerPixel
        
        var data = Data.init(count: length)
        data.withUnsafeMutableBytes { (bytes: UnsafeMutablePointer<UInt8>) -> () in
            
            var pointer = bytes
            /*
             This reserved only [cat,dog,person]
             */
            let reserve = [8, 12, 15]
            
            for pix in res {
                
                let v:UInt8 = reserve.contains(pix) ? 255 : 0
                
                for _ in 0...3 {
                    
                    pointer.pointee = v
                    pointer += 1
                }
            }
        }
        let provider: CGDataProvider = CGDataProvider.init(data: data as CFData)!
        
        let cgimg = CGImage.init(width: w, height: h, bitsPerComponent: bytesPerComponent * 8, bitsPerPixel: bytesPerPixel * 8, bytesPerRow: bytesPerPixel * w, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.init(rawValue: CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)
        
        return cgimg
    }
}

extension UIImage {
    
    public func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        
        return pixelBuffer(width: width, height: height, pixelFormatType: kCVPixelFormatType_32ARGB, colorSpace: CGColorSpaceCreateDeviceRGB(), alphaInfo: .noneSkipFirst)
    }
    
    public func pixelBuffer(width: Int, height: Int, pixelFormatType: OSType, colorSpace: CGColorSpace, alphaInfo: CGImageAlphaInfo) -> CVPixelBuffer? {
        
        var maybePixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue, kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormatType, attrs as CFDictionary, &maybePixelBuffer)
        
        guard status == kCVReturnSuccess, let pixelBuffer = maybePixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.init(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        
        guard let context = CGContext.init(data: pixelData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: colorSpace, bitmapInfo: alphaInfo.rawValue) else {
            return nil
        }
        
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat.init(height))
        context.scaleBy(x: 1, y: -1)
        
        draw(in: CGRect.init(x: 0, y: 0, width: width, height: height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.init(rawValue: 0))
        
        return pixelBuffer
    }
}

extension UIImage {
    
    func resize(size: CGSize!) -> UIImage? {
        
        let rect = CGRect.init(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContext(rect.size)
        
        draw(in: rect)
        
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return img
    }
}

fileprivate class SmoothFillter: CIFilter {
    
    private let kernel: CIColorKernel
    var inputImage: CIImage?
    
    override init() {
        
        let kernelStr = """
            kernel vec4 myColor(__sample source) {
                float maskValue = smoothstep(0.3, 0.5, source.r);
                return vec4(maskValue, maskValue, maskValue, 1);
            }
        """
        
        let kernels = CIColorKernel.makeKernels(source: kernelStr)!
        kernel = kernels[0] as! CIColorKernel
        
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var outputImage: CIImage? {
        
        guard let inputImage = inputImage else {
            return nil
        }
        
        let blurFilter = CIFilter.init(name: "CIGaussianBlur")!
        blurFilter.setDefaults()
        blurFilter.setValue(inputImage.extent.width / 90, forKey: kCIInputRadiusKey)
        blurFilter.setValue(inputImage, forKey: kCIInputImageKey)
        
        let bluredImage = blurFilter.value(forKey: kCIOutputImageKey) as! CIImage
        
        return kernel.apply(extent: bluredImage.extent, arguments: [bluredImage])
    }
}
