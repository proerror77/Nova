//
//  CustomView604.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView604: View {
    @State public var image418Path: String = "image418_42002"
    @State public var text286Text: String = "2"
    @State public var text287Text: String = "Lucy Liu"
    @State public var text288Text: String = "Morgan Stanley"
    @State public var text289Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView605(
                image418Path: image418Path,
                text286Text: text286Text,
                text287Text: text287Text,
                text288Text: text288Text,
                text289Text: text289Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView604_Previews: PreviewProvider {
    static var previews: some View {
        CustomView604()
    }
}
