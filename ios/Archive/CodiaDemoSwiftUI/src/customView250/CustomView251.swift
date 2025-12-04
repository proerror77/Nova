//
//  CustomView251.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView251: View {
    @State public var text141Text: String = "Bruce Li"
    @State public var image184Path: String = "image184_I488441875"
    @State public var image185Path: String = "image185_4885"
    var body: some View {
        HStack(alignment: .center, spacing: 243) {
            CustomView252(
                text141Text: text141Text,
                image184Path: image184Path)
                .frame(width: 100, height: 16)
            Image(image185Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21.999, height: 20.99, alignment: .topLeading)
        }
        .frame(width: 365, height: 20.99, alignment: .topLeading)
    }
}

struct CustomView251_Previews: PreviewProvider {
    static var previews: some View {
        CustomView251()
    }
}
