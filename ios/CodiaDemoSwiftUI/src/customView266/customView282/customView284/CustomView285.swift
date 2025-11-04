//
//  CustomView285.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView285: View {
    @State public var text158Text: String = "Liam"
    @State public var text159Text: String = "Hello, how are you bro~"
    @State public var text160Text: String = "09:41 PM"
    @State public var image205Path: String = "image205_4966"
    @State public var text161Text: String = "1"
    var body: some View {
        HStack(alignment: .center, spacing: -41) {
            CustomView286(
                text158Text: text158Text,
                text159Text: text159Text)
                .frame(width: 161, height: 46)
            CustomView287(
                text160Text: text160Text,
                image205Path: image205Path,
                text161Text: text161Text)
                .frame(width: 161)
        }
        .padding(EdgeInsets(top: 13, leading: 0, bottom: 10, trailing: 0))
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 72, alignment: .top)
    }
}

struct CustomView285_Previews: PreviewProvider {
    static var previews: some View {
        CustomView285()
    }
}
