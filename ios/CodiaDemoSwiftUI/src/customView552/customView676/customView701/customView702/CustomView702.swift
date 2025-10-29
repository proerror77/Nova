//
//  CustomView702.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView702: View {
    @State public var image490Path: String = "image490_42244"
    @State public var text334Text: String = "4"
    @State public var text335Text: String = "Lucy Liu"
    @State public var text336Text: String = "Morgan Stanley"
    @State public var text337Text: String = "2293"
    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            CustomView703(
                image490Path: image490Path,
                text334Text: text334Text,
                text335Text: text335Text,
                text336Text: text336Text,
                text337Text: text337Text)
                .frame(height: 371)
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
        }
        .frame(width: 309, height: 389, alignment: .topLeading)
    }
}

struct CustomView702_Previews: PreviewProvider {
    static var previews: some View {
        CustomView702()
    }
}
