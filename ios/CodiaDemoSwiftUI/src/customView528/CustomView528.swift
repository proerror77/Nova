//
//  CustomView528.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView528: View {
    @State public var image358Path: String = "image358_41822"
    @State public var image359Path: String = "image359_I4182353003"
    @State public var image360Path: String = "image360_I4182353008"
    @State public var text254Text: String = "9:41"
    @State public var image361Path: String = "image361_41825"
    @State public var image362Path: String = "image362_41828"
    @State public var image363Path: String = "image363_41829"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image358Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView529(
                image359Path: image359Path,
                image360Path: image360Path,
                text254Text: text254Text)
                .frame(width: 393, height: 46.113)
            Image(image361Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image362Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 92, y: 729)
            Image(image363Path)
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

struct CustomView528_Previews: PreviewProvider {
    static var previews: some View {
        CustomView528()
    }
}
