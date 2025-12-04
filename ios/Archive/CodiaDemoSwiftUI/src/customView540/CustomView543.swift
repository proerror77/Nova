//
//  CustomView543.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView543: View {
    @State public var text257Text: String = "Go to the Account center"
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(text257Text)
                .foregroundColor(Color(red: 0.32, green: 0.32, blue: 0.32, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 14))
                .lineLimit(1)
                .frame(alignment: .center)
                .multilineTextAlignment(.center)
        }
        .padding(EdgeInsets(top: 6, leading: 90, bottom: 6, trailing: 90))
        .frame(width: 339, height: 33, alignment: .top)
        .background(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 0.00))
        .overlay(RoundedRectangle(cornerRadius: 31).stroke(Color(red: 0.75, green: 0.75, blue: 0.75, opacity: 1.00), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 31))
    }
}

struct CustomView543_Previews: PreviewProvider {
    static var previews: some View {
        CustomView543()
    }
}
