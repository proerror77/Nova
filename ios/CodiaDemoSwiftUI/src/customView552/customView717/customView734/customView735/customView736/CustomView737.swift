//
//  CustomView737.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView737: View {
    @State public var text350Text: String = "3"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView738(text350Text: text350Text)
        }
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .frame(width: 35, height: 35, alignment: .leading)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView737_Previews: PreviewProvider {
    static var previews: some View {
        CustomView737()
    }
}
