//
//  CustomView530.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView530: View {
    @State public var text254Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView531(text254Text: text254Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView530_Previews: PreviewProvider {
    static var previews: some View {
        CustomView530()
    }
}
