//
//  CustomView11.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView11: View {
    @State public var image1Path: String = "image1_I426841881"
    @State public var text3Text: String = "1"
    @State public var text4Text: String = "Lucy Liu"
    @State public var text5Text: String = "Morgan Stanley"
    @State public var text6Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView12(
                image1Path: image1Path,
                text3Text: text3Text,
                text4Text: text4Text,
                text5Text: text5Text,
                text6Text: text6Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView11_Previews: PreviewProvider {
    static var previews: some View {
        CustomView11()
    }
}
