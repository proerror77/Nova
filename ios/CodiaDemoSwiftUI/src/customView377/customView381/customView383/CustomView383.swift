//
//  CustomView383.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView383: View {
    @State public var image250Path: String = "image250_41275"
    @State public var text206Text: String = "All contacts"
    @State public var text207Text: String = "4"
    @State public var image251Path: String = "image251_41288"
    var body: some View {
        HStack(alignment: .center) {
            Image(image250Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 21.891, alignment: .leading)
            CustomView384(
                text206Text: text206Text,
                text207Text: text207Text,
                image251Path: image251Path)
                .frame(width: 319)
        }
        .frame(width: 340.891, height: 60, alignment: .topLeading)
    }
}

struct CustomView383_Previews: PreviewProvider {
    static var previews: some View {
        CustomView383()
    }
}
