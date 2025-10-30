//
//  CustomView544.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView544: View {
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    @State public var image377Path: String = "image377_41859"
    @State public var image378Path: String = "image378_41863"
    @State public var text259Text: String = "Add an alias account (Anonymous)"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView545(
                image376Path: image376Path,
                text258Text: text258Text,
                image377Path: image377Path,
                image378Path: image378Path,
                text259Text: text259Text)
                .frame(width: 300.06)
        }
        .padding(EdgeInsets(top: 13, leading: 19, bottom: 13, trailing: 19))
        .frame(width: 339, height: 127, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct CustomView544_Previews: PreviewProvider {
    static var previews: some View {
        CustomView544()
    }
}
