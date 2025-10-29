//
//  CustomView348.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView348: View {
    @State public var image228Path: String = "image228_41093"
    @State public var text193Text: String = "Share invitation link "
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(image228Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16, alignment: .topLeading)
            Text(text193Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView348_Previews: PreviewProvider {
    static var previews: some View {
        CustomView348()
    }
}
