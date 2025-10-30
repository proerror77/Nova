//
//  CustomView358.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView358: View {
    @State public var image233Path: String = "image233_41121"
    @State public var text198Text: String = "Mobile phone contacts"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView359(
                image233Path: image233Path,
                text198Text: text198Text)
        }
        .padding(EdgeInsets(top: 7, leading: 36, bottom: 7, trailing: 36))
        .frame(width: 350, height: 35, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct CustomView358_Previews: PreviewProvider {
    static var previews: some View {
        CustomView358()
    }
}
