//
//  CustomView467.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView467: View {
    @State public var image290Path: String = "image290_41448"
    @State public var text234Text: String = "Drafts"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView468(
                image290Path: image290Path,
                text234Text: text234Text)
        }
        .padding(EdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11))
        .frame(width: 75, height: 28, alignment: .topLeading)
        .background(Color(red: 0.21, green: 0.21, blue: 0.21, opacity: 1.00))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView467_Previews: PreviewProvider {
    static var previews: some View {
        CustomView467()
    }
}
