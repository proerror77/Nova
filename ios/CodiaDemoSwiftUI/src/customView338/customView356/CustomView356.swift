//
//  CustomView356.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView356: View {
    @State public var image232Path: String = "image232_41114"
    @State public var text197Text: String = "Add a contact"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView357(
                image232Path: image232Path,
                text197Text: text197Text)
        }
        .padding(EdgeInsets(top: 7, leading: 36, bottom: 7, trailing: 36))
        .frame(width: 350, height: 35, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct CustomView356_Previews: PreviewProvider {
    static var previews: some View {
        CustomView356()
    }
}
