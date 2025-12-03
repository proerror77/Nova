//
//  CustomView538.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView538: View {
    @State public var text256Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView539(text256Text: text256Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView538_Previews: PreviewProvider {
    static var previews: some View {
        CustomView538()
    }
}
