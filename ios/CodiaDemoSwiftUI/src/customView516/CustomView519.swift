//
//  CustomView519.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView519: View {
    @State public var text251Text: String = "9:41"
    var body: some View {
        ZStack(alignment: .topLeading) {
                HStack {
                    Spacer()
                        Text(text251Text)
                            .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                            .font(.custom("SFProText-Semibold", size: 15))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 1)
        }
        .frame(width: 54, height: 21, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct CustomView519_Previews: PreviewProvider {
    static var previews: some View {
        CustomView519()
    }
}
