//
//  CustomView63.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView63: View {
    @State public var image47Path: String = "image47_4351"
    @State public var text36Text: String = "93"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView64(
                image47Path: image47Path,
                text36Text: text36Text)
                .frame(width: 40.43, height: 18.654)
        }
        .frame(width: 40.43, height: 18.654, alignment: .topLeading)
    }
}

struct CustomView63_Previews: PreviewProvider {
    static var previews: some View {
        CustomView63()
    }
}
