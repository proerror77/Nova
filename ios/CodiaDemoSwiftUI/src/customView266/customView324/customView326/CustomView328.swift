//
//  CustomView328.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView328: View {
    @State public var text182Text: String = "Liam"
    @State public var text183Text: String = "Hello, how are you bro~"
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text182Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 19))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text183Text)
                .foregroundColor(Color(red: 0.54, green: 0.54, blue: 0.54, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 15))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 161, height: 46, alignment: .topLeading)
    }
}

struct CustomView328_Previews: PreviewProvider {
    static var previews: some View {
        CustomView328()
    }
}
