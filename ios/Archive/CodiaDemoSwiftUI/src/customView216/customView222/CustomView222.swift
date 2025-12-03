//
//  CustomView222.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView222: View {
    @State public var image160Path: String = "image160_I479741093"
    @State public var text118Text: String = "Share invitation link "
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CustomView223(
                image160Path: image160Path,
                text118Text: text118Text)
        }
        .padding(EdgeInsets(top: 7, leading: 37, bottom: 7, trailing: 37))
        .frame(width: 350, height: 35, alignment: .top)
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }
}

struct CustomView222_Previews: PreviewProvider {
    static var previews: some View {
        CustomView222()
    }
}
