//
//  CustomView536.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView536: View {
    @State public var image370Path: String = "image370_41840"
    @State public var image371Path: String = "image371_I4184153003"
    @State public var image372Path: String = "image372_I4184153008"
    @State public var text256Text: String = "9:41"
    @State public var image373Path: String = "image373_41843"
    @State public var image374Path: String = "image374_41846"
    @State public var image375Path: String = "image375_41847"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image370Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 578, height: 1266, alignment: .topLeading)
                .offset(x: -69, y: -247)
            CustomView537(
                image371Path: image371Path,
                image372Path: image372Path,
                text256Text: text256Text)
                .frame(width: 393, height: 46.113)
            Image(image373Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64, alignment: .topLeading)
                .offset(x: 156, y: 717)
            Image(image374Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40, alignment: .topLeading)
                .offset(x: 92, y: 729)
            Image(image375Path)
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

struct CustomView536_Previews: PreviewProvider {
    static var previews: some View {
        CustomView536()
    }
}
