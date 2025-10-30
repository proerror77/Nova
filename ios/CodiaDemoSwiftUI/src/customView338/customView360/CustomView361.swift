//
//  CustomView361.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView361: View {
    @State public var image234Path: String = "image234_41125"
    @State public var text199Text: String = "Scan the code"
    var body: some View {
        HStack(alignment: .top, spacing: 21) {
            Image(image234Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 21, height: 21, alignment: .topLeading)
            Text(text199Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView361_Previews: PreviewProvider {
    static var previews: some View {
        CustomView361()
    }
}
