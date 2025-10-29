//
//  CustomView212.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView212: View {
    @State public var text111Text: String = "Apple iPhone17"
    @State public var text112Text: String = "Last active: Invalid Date"
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text111Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 16))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text112Text)
                .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 12))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .frame(width: 161, height: 46, alignment: .topLeading)
    }
}

struct CustomView212_Previews: PreviewProvider {
    static var previews: some View {
        CustomView212()
    }
}
