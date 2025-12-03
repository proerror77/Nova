//
//  CustomView462.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView462: View {
    @State public var image287Path: String = "image287_41437"
    @State public var image288Path: String = "image288_41441"
    @State public var text233Text: String = "All"
    @State public var image289Path: String = "image289_41444"
    @State public var image290Path: String = "image290_41448"
    @State public var text234Text: String = "Drafts"
    @State public var text235Text: String = "All"
    @State public var text236Text: String = "Video"
    @State public var text237Text: String = "Photos"
    @State public var image291Path: String = "image291_41458"
    @State public var image292Path: String = "image292_41461"
    @State public var image293Path: String = "image293_41486"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.03, green: 0.02, blue: 0.01, opacity: 1.00))
                .frame(width: 393, height: 852)
            Image(image287Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 141, height: 5, alignment: .top)
                .offset(x: 126, y: 836)
            CustomView464(
                image288Path: image288Path,
                text233Text: text233Text,
                image289Path: image289Path,
                image290Path: image290Path,
                text234Text: text234Text)
                .frame(width: 348, height: 28)
                .offset(x: 22, y: 62)
            CustomView469(
                text235Text: text235Text,
                text236Text: text236Text,
                text237Text: text237Text,
                image291Path: image291Path)
                .frame(width: 336, height: 45)
                .offset(x: 34, y: 102)
            Image(image292Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 388, height: 778, alignment: .top)
                .offset(x: 2, y: 151)
            Image(image293Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 393, height: 47, alignment: .topLeading)
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView462_Previews: PreviewProvider {
    static var previews: some View {
        CustomView462()
    }
}
