//
//  CustomView570.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView570: View {
    @State public var image394Path: String = "image394_41921"
    @State public var text270Text: String = "3"
    @State public var text271Text: String = "Lucy Liu"
    @State public var text272Text: String = "Morgan Stanley"
    @State public var text273Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView571(
                image394Path: image394Path,
                text270Text: text270Text,
                text271Text: text271Text,
                text272Text: text272Text,
                text273Text: text273Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 312, height: 392, alignment: .topLeading)
    }
}

struct CustomView570_Previews: PreviewProvider {
    static var previews: some View {
        CustomView570()
    }
}
