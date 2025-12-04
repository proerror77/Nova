//
//  CustomView68.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView68: View {
    @State public var image60Path: String = "image60_4388"
    @State public var text41Text: String = "Home"
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(image60Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 20, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(text41Text)
                .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 9))
                .lineLimit(1)
                .frame(height: 22, alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 38, height: 44, alignment: .topLeading)
    }
}

struct CustomView68_Previews: PreviewProvider {
    static var previews: some View {
        CustomView68()
    }
}
