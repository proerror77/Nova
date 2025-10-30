//
//  CustomView98.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView98: View {
    @State public var text62Text: String = "William Rhodes"
    @State public var text63Text: String = "10m"
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text62Text)
                .foregroundColor(Color(red: 0.03, green: 0.02, blue: 0.01, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 5.5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
            Text(text63Text)
                .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34, opacity: 1.00))
                .font(.custom("HelveticaNeue-Medium", size: 5))
                .lineLimit(1)
                .frame(alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 40, alignment: .leading)
    }
}

struct CustomView98_Previews: PreviewProvider {
    static var previews: some View {
        CustomView98()
    }
}
