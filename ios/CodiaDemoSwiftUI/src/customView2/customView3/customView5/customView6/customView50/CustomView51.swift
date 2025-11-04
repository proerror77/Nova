//
//  CustomView51.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView51: View {
    @State public var text23Text: String = "view more"
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Text(text23Text)
                .foregroundColor(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00))
                .font(.custom("HelveticaNeue", size: 13))
                .lineLimit(1)
                .frame(width: 60, height: 16, alignment: .center)
                .multilineTextAlignment(.center)
            Rectangle()
                .fill(Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.81, green: 0.13, blue: 0.25, opacity: 1.00), lineWidth: 1))
                .frame(width: 58, height: 1)
        }
        .padding(EdgeInsets(top: 3, leading: 2, bottom: 3, trailing: 2))
        .frame(width: 60.153, height: 17, alignment: .top)
    }
}

struct CustomView51_Previews: PreviewProvider {
    static var previews: some View {
        CustomView51()
    }
}
