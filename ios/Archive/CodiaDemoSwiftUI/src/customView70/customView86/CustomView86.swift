//
//  CustomView86.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView86: View {
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
        HStack(alignment: .center, spacing: 10) {
            CustomView87(
                image76Path: image76Path,
                text57Text: text57Text,
                text58Text: text58Text,
                image77Path: image77Path,
                image78Path: image78Path,
                text59Text: text59Text,
                text60Text: text60Text,
                image79Path: image79Path,
                text61Text: text61Text)
                .frame(width: 175)
        }
        .padding(EdgeInsets(top: 6, leading: 5, bottom: 6, trailing: 5))
        .frame(width: 185, height: 278, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CustomView86_Previews: PreviewProvider {
    static var previews: some View {
        CustomView86()
    }
}
