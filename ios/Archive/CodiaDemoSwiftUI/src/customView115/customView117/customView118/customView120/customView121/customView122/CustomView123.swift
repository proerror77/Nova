//
//  CustomView123.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView123: View {
    @State public var image97Path: String = "image97_4540"
    @State public var text74Text: String = "Number of posts"
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(image97Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 37, height: 37, alignment: .topLeading)
            Text(text74Text)
                .foregroundColor(Color(red: 0.66, green: 0.66, blue: 0.66, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView123_Previews: PreviewProvider {
    static var previews: some View {
        CustomView123()
    }
}
