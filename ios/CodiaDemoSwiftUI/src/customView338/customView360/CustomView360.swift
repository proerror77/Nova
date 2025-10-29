//
//  CustomView360.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView360: View {
    @State public var image234Path: String = "image234_41125"
    @State public var text199Text: String = "Scan the code"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView361(
                image234Path: image234Path,
                text199Text: text199Text)
        }
        .padding(EdgeInsets(top: 6, leading: 35, bottom: 6, trailing: 35))
        .frame(width: 350, height: 35, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct CustomView360_Previews: PreviewProvider {
    static var previews: some View {
        CustomView360()
    }
}
