//
//  CustomView645.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView645: View {
    @State public var image448Path: String = "image448_42103"
    @State public var text306Text: String = "2"
    @State public var text307Text: String = "Lucy Liu"
    @State public var text308Text: String = "Morgan Stanley"
    @State public var text309Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView646(
                image448Path: image448Path,
                text306Text: text306Text,
                text307Text: text307Text,
                text308Text: text308Text,
                text309Text: text309Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView645_Previews: PreviewProvider {
    static var previews: some View {
        CustomView645()
    }
}
