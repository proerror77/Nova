//
//  CustomView271.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView271: View {
    @State public var text149Text: String = "Liam"
    @State public var text150Text: String = "Hello, how are you bro~"
    @State public var text151Text: String = "09:41 PM"
    @State public var image195Path: String = "image195_4930"
    @State public var text152Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView272(
                text149Text: text149Text,
                text150Text: text150Text)
                .frame(width: 161, height: 46)
            CustomView273(
                text151Text: text151Text,
                image195Path: image195Path,
                text152Text: text152Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView271_Previews: PreviewProvider {
    static var previews: some View {
        CustomView271()
    }
}
