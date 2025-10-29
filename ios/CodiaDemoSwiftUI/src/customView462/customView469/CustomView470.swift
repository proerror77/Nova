//
//  CustomView470.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView470: View {
    @State public var text235Text: String = "All"
    @State public var text236Text: String = "Video"
    @State public var text237Text: String = "Photos"
    var body: some View {
        HStack(alignment: .center, spacing: 57) {
            Text(text235Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text236Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text237Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 20))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView470_Previews: PreviewProvider {
    static var previews: some View {
        CustomView470()
    }
}
