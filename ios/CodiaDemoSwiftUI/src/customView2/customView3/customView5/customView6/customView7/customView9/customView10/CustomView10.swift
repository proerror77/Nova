//
//  CustomView10.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView10: View {
    @State public var image1Path: String = "image1_I426841881"
    @State public var text3Text: String = "1"
    @State public var text4Text: String = "Lucy Liu"
    @State public var text5Text: String = "Morgan Stanley"
    @State public var text6Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView11(
                image1Path: image1Path,
                text3Text: text3Text,
                text4Text: text4Text,
                text5Text: text5Text,
                text6Text: text6Text)
                .frame(width: 309, height: 389)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView10_Previews: PreviewProvider {
    static var previews: some View {
        CustomView10()
    }
}
