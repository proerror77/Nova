//
//  CustomView701.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView701: View {
    @State public var image490Path: String = "image490_42244"
    @State public var text334Text: String = "4"
    @State public var text335Text: String = "Lucy Liu"
    @State public var text336Text: String = "Morgan Stanley"
    @State public var text337Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView702(
                image490Path: image490Path,
                text334Text: text334Text,
                text335Text: text335Text,
                text336Text: text336Text,
                text337Text: text337Text)
                .frame(width: 309, height: 389)
                .offset(x: 1)
        }
        .frame(width: 311, height: 392, alignment: .topLeading)
    }
}

struct CustomView701_Previews: PreviewProvider {
    static var previews: some View {
        CustomView701()
    }
}
