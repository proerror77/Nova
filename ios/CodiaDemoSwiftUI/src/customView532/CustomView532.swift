//
//  CustomView532.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView532: View {
    @State public var image364Path: String = "image364_41831"
    @State public var image365Path: String = "image365_I4183253003"
    @State public var image366Path: String = "image366_I4183253008"
    @State public var text255Text: String = "9:41"
    @State public var image367Path: String = "image367_41834"
    @State public var image368Path: String = "image368_41837"
    @State public var image369Path: String = "image369_41838"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image364Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView533(
                image365Path: image365Path,
                image366Path: image366Path,
                text255Text: text255Text)
                .frame(width: 393, height: 46.113)
            Image(image367Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image368Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 92, y: 729)
            Image(image369Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20, alignment: .topLeading)
                .offset(x: 22, y: 66)
        }
        .frame(width: 393, height: 851, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView532_Previews: PreviewProvider {
    static var previews: some View {
        CustomView532()
    }
}
