//
//  CustomView514.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView514: View {
    @State public var text250Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView515(text250Text: text250Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView514_Previews: PreviewProvider {
    static var previews: some View {
        CustomView514()
    }
}
