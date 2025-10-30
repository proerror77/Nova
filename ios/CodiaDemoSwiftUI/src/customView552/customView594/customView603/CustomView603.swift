//
//  CustomView603.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView603: View {
    @State public var image418Path: String = "image418_42002"
    @State public var text286Text: String = "2"
    @State public var text287Text: String = "Lucy Liu"
    @State public var text288Text: String = "Morgan Stanley"
    @State public var text289Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView604(
                image418Path: image418Path,
                text286Text: text286Text,
                text287Text: text287Text,
                text288Text: text288Text,
                text289Text: text289Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView603_Previews: PreviewProvider {
    static var previews: some View {
        CustomView603()
    }
}
