//
//  CustomView87.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView87: View {
    @State public var image76Path: String = "image76_4451"
    @State public var text57Text: String = "William Rhodes"
    @State public var text58Text: String = "10m"
    @State public var image77Path: String = "image77_4455"
    @State public var image78Path: String = "image78_4458"
    @State public var text59Text: String = "kyleegigstead Cyborg dreams"
    @State public var text60Text: String = "kyleegigstead Cyborg dreams"
    @State public var image79Path: String = "image79_4464"
    @State public var text61Text: String = "2293"
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CustomView88(
                image76Path: image76Path,
                text57Text: text57Text,
                text58Text: text58Text,
                image77Path: image77Path)
            Image(image78Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 223, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(7)
            CustomView91(
                text59Text: text59Text,
                text60Text: text60Text,
                image79Path: image79Path,
                text61Text: text61Text)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 175, alignment: .leading)
    }
}

struct CustomView87_Previews: PreviewProvider {
    static var previews: some View {
        CustomView87()
    }
}
