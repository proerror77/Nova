//
//  CustomView177.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView177: View {
    @State public var text91Text: String = "Dark Mode"
    @State public var image123Path: String = "image123_4679"
    var body: some View {
        HStack(alignment: .center, spacing: 169) {
            Text(text91Text)
                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Image(image123Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 33, height: 17, alignment: .topLeading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView177_Previews: PreviewProvider {
    static var previews: some View {
        CustomView177()
    }
}
