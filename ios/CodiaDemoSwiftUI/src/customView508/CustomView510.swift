//
//  CustomView510.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView510: View {
    @State public var text249Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView511(text249Text: text249Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView510_Previews: PreviewProvider {
    static var previews: some View {
        CustomView510()
    }
}
