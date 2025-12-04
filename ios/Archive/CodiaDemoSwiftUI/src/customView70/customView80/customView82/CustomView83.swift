//
//  CustomView83.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView83: View {
    @State public var text51Text: String = "Following"
    @State public var text52Text: String = "3021"
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text51Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text52Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 139, alignment: .leading)
    }
}

struct CustomView83_Previews: PreviewProvider {
    static var previews: some View {
        CustomView83()
    }
}
