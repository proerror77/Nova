//
//  CustomView347.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView347: View {
    @State public var image228Path: String = "image228_41093"
    @State public var text193Text: String = "Share invitation link "
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView348(
                image228Path: image228Path,
                text193Text: text193Text)
        }
        .padding(EdgeInsets(top: 7, leading: 37, bottom: 7, trailing: 37))
        .frame(width: 350, height: 35, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct CustomView347_Previews: PreviewProvider {
    static var previews: some View {
        CustomView347()
    }
}
