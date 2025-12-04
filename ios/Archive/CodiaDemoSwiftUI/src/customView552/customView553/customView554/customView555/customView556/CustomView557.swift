//
//  CustomView557.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView557: View {
    @State public var text262Text: String = "1"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView558(text262Text: text262Text)
        }
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .frame(width: 35, height: 35, alignment: .leading)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView557_Previews: PreviewProvider {
    static var previews: some View {
        CustomView557()
    }
}
