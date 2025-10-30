//
//  CustomView256.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView256: View {
    @State public var text143Text: String = "Following"
    @State public var text144Text: String = "Followers"
    var body: some View {
        HStack(alignment: .center, spacing: 100) {
            Text(text143Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            CustomView257(text144Text: text144Text)
                .frame(width: 81, height: 20)
        }
        .frame(width: 271, height: 20, alignment: .topLeading)
    }
}

struct CustomView256_Previews: PreviewProvider {
    static var previews: some View {
        CustomView256()
    }
}
