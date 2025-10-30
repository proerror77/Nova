//
//  CustomView729.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView729: View {
    @State public var text346Text: String = "2"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView730(text346Text: text346Text)
        }
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .frame(width: 35, height: 35, alignment: .leading)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView729_Previews: PreviewProvider {
    static var previews: some View {
        CustomView729()
    }
}
