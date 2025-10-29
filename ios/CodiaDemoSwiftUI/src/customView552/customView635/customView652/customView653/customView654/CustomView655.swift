//
//  CustomView655.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView655: View {
    @State public var text310Text: String = "3"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView656(text310Text: text310Text)
        }
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .frame(width: 35, height: 35, alignment: .leading)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView655_Previews: PreviewProvider {
    static var previews: some View {
        CustomView655()
    }
}
