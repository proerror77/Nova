//
//  CustomView522.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView522: View {
    @State public var text252Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView523(text252Text: text252Text)
                .frame(width: 54, height: 21)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView522_Previews: PreviewProvider {
    static var previews: some View {
        CustomView522()
    }
}
