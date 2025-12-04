//
//  CustomView37.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView37: View {
    @State public var text15Text: String = "4"
    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            CustomView38(text15Text: text15Text)
        }
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .frame(width: 35, height: 35, alignment: .leading)
        .background(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView37_Previews: PreviewProvider {
    static var previews: some View {
        CustomView37()
    }
}
