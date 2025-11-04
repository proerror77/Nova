//
//  CustomView512.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView512: View {
    @State public var image328Path: String = "image328_41770"
    @State public var image329Path: String = "image329_I4177153003"
    @State public var image330Path: String = "image330_I4177153008"
    @State public var text250Text: String = "9:41"
    @State public var image331Path: String = "image331_41773"
    @State public var image332Path: String = "image332_41774"
    @State public var image333Path: String = "image333_41775"
    @State public var image334Path: String = "image334_41776"
    @State public var image335Path: String = "image335_41781"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image328Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView513(
                image329Path: image329Path,
                image330Path: image330Path,
                text250Text: text250Text)
                .frame(width: 393, height: 46.167)
            Image(image331Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 244, y: 730)
            Image(image332Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 10, height: 10, alignment: .topLeading)
                .cornerRadius(5)
                .offset(x: 110, y: 8)
            Image(image333Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 6, height: 6, alignment: .topLeading)
                .cornerRadius(3)
                .offset(x: 271, y: 10)
            Image(image334Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image335Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView512_Previews: PreviewProvider {
    static var previews: some View {
        CustomView512()
    }
}
