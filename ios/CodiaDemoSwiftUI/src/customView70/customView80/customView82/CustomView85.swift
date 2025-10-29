//
//  CustomView85.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView85: View {
    @State public var text55Text: String = "Likes"
    @State public var text56Text: String = "3021"
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(text55Text)
                .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text56Text)
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

struct CustomView85_Previews: PreviewProvider {
    static var previews: some View {
        CustomView85()
    }
}
