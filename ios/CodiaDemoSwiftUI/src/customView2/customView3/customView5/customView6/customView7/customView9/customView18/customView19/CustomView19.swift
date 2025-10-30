//
//  CustomView19.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView19: View {
    @State public var image7Path: String = "image7_I426841901"
    @State public var text7Text: String = "2"
    @State public var text8Text: String = "Lucy Liu"
    @State public var text9Text: String = "Morgan Stanley"
    @State public var text10Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView20(
                image7Path: image7Path,
                text7Text: text7Text,
                text8Text: text8Text,
                text9Text: text9Text,
                text10Text: text10Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView19_Previews: PreviewProvider {
    static var previews: some View {
        CustomView19()
    }
}
