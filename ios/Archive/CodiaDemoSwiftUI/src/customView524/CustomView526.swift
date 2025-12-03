//
//  CustomView526.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView526: View {
    @State public var text253Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView527(text253Text: text253Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView526_Previews: PreviewProvider {
    static var previews: some View {
        CustomView526()
    }
}
