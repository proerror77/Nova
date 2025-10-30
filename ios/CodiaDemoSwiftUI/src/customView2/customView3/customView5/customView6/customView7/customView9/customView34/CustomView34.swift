//
//  CustomView34.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView34: View {
    @State public var image19Path: String = "image19_I426841941"
    @State public var text15Text: String = "4"
    @State public var text16Text: String = "Lucy Liu"
    @State public var text17Text: String = "Morgan Stanley"
    @State public var text18Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView35(
                image19Path: image19Path,
                text15Text: text15Text,
                text16Text: text16Text,
                text17Text: text17Text,
                text18Text: text18Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView34_Previews: PreviewProvider {
    static var previews: some View {
        CustomView34()
    }
}
