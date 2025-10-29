//
//  CustomView547.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView547: View {
    @State public var image376Path: String = "image376_41857"
    @State public var text258Text: String = "Account_one (Primary)"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(image376Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 42, height: 42, alignment: .topLeading)
                .cornerRadius(21)
            Text(text258Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 14))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct CustomView547_Previews: PreviewProvider {
    static var previews: some View {
        CustomView547()
    }
}
