//
//  CustomView79.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView79: View {
    @State public var text46Text: String = "Posts"
    @State public var text47Text: String = "Saved"
    @State public var text48Text: String = "Liked"
    var body: some View {
        HStack(alignment: .center, spacing: 42) {
            Text(text46Text)
                .foregroundColor(Color(red: 0.82, green: 0.11, blue: 0.26, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text47Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
            Text(text48Text)
                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                .font(.custom("HelveticaNeue-Bold", size: 16.5))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .frame(width: 222, height: 20, alignment: .top)
    }
}

struct CustomView79_Previews: PreviewProvider {
    static var previews: some View {
        CustomView79()
    }
}
