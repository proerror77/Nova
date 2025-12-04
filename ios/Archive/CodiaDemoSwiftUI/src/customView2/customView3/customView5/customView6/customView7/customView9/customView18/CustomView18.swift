//
//  CustomView18.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView18: View {
    @State public var image7Path: String = "image7_I426841901"
    @State public var text7Text: String = "2"
    @State public var text8Text: String = "Lucy Liu"
    @State public var text9Text: String = "Morgan Stanley"
    @State public var text10Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView19(
                image7Path: image7Path,
                text7Text: text7Text,
                text8Text: text8Text,
                text9Text: text9Text,
                text10Text: text10Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView18_Previews: PreviewProvider {
    static var previews: some View {
        CustomView18()
    }
}
