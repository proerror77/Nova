//
//  CustomView263.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView263: View {
    @State public var text147Text: String = "Following"
    @State public var text148Text: String = "Followers"
    var body: some View {
        HStack(alignment: .center, spacing: 100) {
            CustomView264(text147Text: text147Text)
                .frame(width: 81, height: 20)
            Text(text148Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 18))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 271, height: 20, alignment: .topLeading)
    }
}

struct CustomView263_Previews: PreviewProvider {
    static var previews: some View {
        CustomView263()
    }
}
